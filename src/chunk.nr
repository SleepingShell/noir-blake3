use crate::compression;
use dep::std;

/// Configuration constants
global BLOCK_LEN: Field = 16;
global CHUNK_LEN: Field = 256;

/// Flag constants
global CHUNK_START: u32 = 1;
global CHUNK_END: u32 = 2;
global PARENT: u32 = 4;
global ROOT: u32 = 8;
global KEYED_HASH: u32 = 16;
global DERIVE_KEY_CONTEXT: u32 = 32;
global DERIVE_KEY_MATERIAL: u32 = 64;


/// Each chunk can compress up to 1024 bytes (256 32-bit words)
struct ChunkState {
    chaining_value: [u32; 8],

    // The counter for this chunk
    chunk_counter: Field,

    // The current buffer of data
    block: [u32; BLOCK_LEN],
    
    // The current populated block length
    block_len: Field,

    // The number of blocks that were compressed in this chunk
    blocks_compressed: Field,

    // Flags
    flags: u32
}

impl ChunkState {
    /// Instantiate a new chunk, which can compress up to 1024 bytes. 
    /// `key_words` is the initial chaining value of the chunk
    fn new(key_words: [u32; 8], chunk_counter: Field, flags: u32) -> Self {
        Self {
            chaining_value: key_words,
            chunk_counter,
            block: [0; BLOCK_LEN],
            block_len: 0,
            blocks_compressed: 0,
            flags
        }
    }

    fn len(self) -> Field {
        BLOCK_LEN * self.blocks_compressed + self.block_len
    }

    /// TODO: Remove mutability on Noir allowing &mut self -> &self calls
    /// Determine if we are a CHUNK_START
    fn start_flag(self) -> u32 {
        if self.blocks_compressed == 0 {
            CHUNK_START
        } else {
            0
        }
    }

    fn start_flag_mut(&mut self) -> u32 {
        if self.blocks_compressed == 0 {
            CHUNK_START
        } else {
            0
        }
    }

    fn update(&mut self, input: [u32]) {
        let num_blocks = ((input.len() as u64 / BLOCK_LEN as u64) + 1) as Field;
        let mut input_words_left = input.len();
        for i in 0..num_blocks {
            // If the block buffer is full, compress it and clear.
            if self.block_len == BLOCK_LEN {
                let compressed = compression::compress(
                    self.chaining_value,
                    self.chunk_counter,
                    BLOCK_LEN,
                    self.flags + self.start_flag_mut(),
                    self.block
                );
                self.chaining_value = first_8_words(compressed);
                self.blocks_compressed += 1;
                self.block = [0; BLOCK_LEN];
                self.block_len = 0;
            }

            let offset = self.block_len;
            let take = min(BLOCK_LEN - offset, input_words_left);
            for j in 0..take {
                self.block[offset+j] = input[BLOCK_LEN*i + j];
            }
            self.block_len += take;
            input_words_left -= take;
        }
    }

    fn output(self) -> Output {
        Output {
            input_chaining_value: self.chaining_value,
            block: self.block,
            counter: self.chunk_counter,
            block_len: self.block_len,
            flags: self.flags + self.start_flag() + CHUNK_END
        }
    }
}

struct Output {
    input_chaining_value: [u32; 8],
    block: [u32; 16],
    counter: Field,
    block_len: Field,
    flags: u32
}

impl Output {
    fn chaining_value(self) -> [u32; 8] {
        first_8_words(compression::compress(
            self.input_chaining_value,
            self.counter,
            self.block_len,
            self.flags,
            self.block
        ))
    }

    fn root_output_bytes<N>(self) -> [u32; N] {
        let mut result = [0; N];
        let mut output_block_counter = 0;
        let flags = self.flags + ROOT;

        for i in 0..(N as u64/16)+1 {
            let words = compression::compress(
                self.input_chaining_value,
                output_block_counter,
                self.block_len,
                flags,
                self.block
            );

            let take = min(16, N-16*(i as Field));
            for j in 0..take {
                result[16*i as Field + j] = words[j];
            }
        }

        result
    }
}

fn parent_output(
    left_child_cv: [u32; 8],
    right_child_cv: [u32; 8],
    key_words: [u32; 8],
    flags: u32
) -> Output {
    let mut block_words = [0; 16];
    for i in 0..8 {
        block_words[i] = left_child_cv[i];
        block_words[i+8] = right_child_cv[i];
    }

    Output {
        input_chaining_value: key_words,
        block: block_words,
        counter: 0,
        block_len: BLOCK_LEN,
        flags: flags + PARENT
    }
}

fn parent_cv(
    left_child_cv: [u32; 8],
    right_child_cv: [u32; 8],
    key_words: [u32; 8],
    flags: u32
) -> [u32; 8] {
    parent_output(left_child_cv, right_child_cv, key_words, flags).chaining_value()
}

/// TODO: Unnecessary when Noir enables indexing arrays by a range
/// Get the first 8 words
fn first_8_words(x: [u32; 16]) -> [u32; 8] {
    let mut res = [0; 8];
    for i in 0..8 {
        res[i] = x[i];
    }
    res
}

fn min(x: Field, y: Field) -> Field {
    if x as u126 > y as u126 {
        y
    } else {
        x
    }
}