mod compression;
mod chunk;

use dep::std;

struct Blake3Hasher {
    chunk_state: chunk::ChunkState,
    key_words: [u32; 8],

    // The cv stack according to section 5.1.2. Chunks's resulting chaining values are pushed onto a stack
    // and they are popped off the stack in order to complete subtrees
    cv_stack: [[u32; 8]],
    cv_stack_len: Field,
    flags: u32
}

impl Blake3Hasher {
    fn new_internal(key_words: [u32; 8], flags: u32) -> Self {
        Self {
            chunk_state: chunk::ChunkState::new(key_words, 0, flags),
            key_words,
            cv_stack: [],
            cv_stack_len: 0,
            flags
        }
    }

    fn new() -> Self {
        Blake3Hasher::new_internal(compression::IV, 0)
    }

    fn push_stack(&mut self, cv: [u32; 8]) {
        self.cv_stack = self.cv_stack.push_back(cv);
        self.cv_stack_len += 1;
    }

    fn pop_stack(&mut self) -> [u32; 8] {
        self.cv_stack_len -= 1;
        let (popped, res) = self.cv_stack.pop_back();
        self.cv_stack = popped;
        res
    }

    fn add_chunk_chaining_value(&mut self, mut new_cv: [u32; 8], mut total_chunks: Field) {
        total_chunks = lsb_zeros(total_chunks);
        for i in 0..total_chunks {
            new_cv = chunk::parent_cv(self.pop_stack(), new_cv, self.key_words, self.flags);
        }
        self.push_stack(new_cv);
    }

    fn update<N>(&mut self, mut input: [u32; N]) {
        let num_chunks = N / chunk::CHUNK_LEN + 1;
        let mut input_words_left = N;
        for i in 0..num_chunks {
            if self.chunk_state.len() == chunk::CHUNK_LEN {
                let chunk_cv = self.chunk_state.chaining_value;
                let total_chunks = self.chunk_state.chunk_counter + 1;
                self.add_chunk_chaining_value(chunk_cv, total_chunks);
                self.chunk_state = chunk::ChunkState::new(self.key_words, total_chunks, self.flags);
            }

            let offset = self.chunk_state.len();
            let take = chunk::min(chunk::CHUNK_LEN - offset, input_words_left);
            let mut to_update = [];
            for j in 0..take {
                to_update = to_update.push_back(input[chunk::CHUNK_LEN*i+j]);
            }
            self.chunk_state.update(to_update);
            input_words_left -= take;
        }
    }

    fn finalize<N>(self) -> [u32; N] {
        let mut output = self.chunk_state.output();
        let mut parent_nodes = self.cv_stack_len;
        for i in 0..parent_nodes {
            parent_nodes -= 1;
            output = chunk::parent_output(
                self.cv_stack[parent_nodes],
                output.chaining_value(),
                self.key_words,
                self.flags
            );
        }

        output.root_output_bytes()
    }
}

/// Get the number of zeros starting at the lsb
/// Calls the unconstrained implementation
/// TODO: I don't think this assertion is enough
fn lsb_zeros(x: Field) -> Field {
    let result = lsb_zeros_impl(x);
    assert(x as u64 >= 2.pow_32(result) as u64);
    result
}

unconstrained fn lsb_zeros_impl(x: Field) -> Field {
    let bits = x.to_le_bits(64);
    let mut result = 0;
    let mut triggered = false;
    for i in 0..64 {
        if bits[i] == 1 {
            if !triggered {
                result = i;
                triggered = true;
            }
        }
    }
    result
}

#[test]
fn test_lsb_zeros() {
    assert(lsb_zeros(3) == 0);
    assert(lsb_zeros(2) == 1);
    assert(lsb_zeros(4) == 2);
    assert(lsb_zeros(5) == 0);
}

// Infinite loop, crashes system. I'm thinking maybe need to change chunk_state.update() to also be generic and have a compile-time bounded loop
#[test]
fn test_hasher() {
    let mut hasher = Blake3Hasher::new();
    let input = [100,200,300];
    hasher.update(input);

    let output: [u32; 16] = hasher.finalize();
    std::println(output);
}