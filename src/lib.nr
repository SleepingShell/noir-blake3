mod compression;
mod chunk;

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
}