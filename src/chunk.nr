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
    chunk_counter: u64,

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
    fn new(key_words: [u32; 8], chunk_counter: u64, flags: u32) -> Self {
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
    fn start_flag(&mut self) -> u32 {
        if self.blocks_compressed == 0 {
            CHUNK_START
        } else {
            0
        }
    }

    fn update(&mut self, input: [u32]) {
        let num_blocks = (input.len() / BLOCK_LEN) + 1;
        let mut input_words_left = input.len();
        for i in 0..num_blocks {
            // If the block buffer is full, compress it and clear.
            if self.block_len == BLOCK_LEN {
                let compressed = compression::compress(
                    self.chaining_value,
                    self.chunk_counter,
                    BLOCK_LEN as u32,
                    self.flags + self.start_flag(),
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
}

fn parent_cv(
    left_child_cv: [u32; 8],
    right_child_cv: [u32; 8],
    key_words: [u32; 8],
    flags: u32
) -> [u32; 8] {
    let mut block_words = [0; 16];
    for i in 0..8 {
        block_words[i] = left_child_cv[i];
        block_words[i+8] = right_child_cv[i];
    }
    let compressed = compression::compress(
        key_words,
        0,
        BLOCK_LEN as u32,
        flags + ROOT,
        block_words
    );
    first_8_words(compressed)
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