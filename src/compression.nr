use dep::std;

global IV: [u32; 8] = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19];
global MSG_PERMUTATION: [Field; 16] = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8];

struct Blake3State {
    state: [u32; 16],
    message_block: [u32; 16]
}

impl Blake3State {
    fn new(input_chain: [u32; 8], counter: Field, block_len: u32, flags: u32, message_block: [u32; 16]) -> Self {
        Self {
            state: [
                input_chain[0], input_chain[1],
                input_chain[2], input_chain[3],
                input_chain[4], input_chain[5],
                input_chain[6], input_chain[7],
                IV[0], IV[1], IV[2], IV[3],
                counter as u32, (counter as u64 >> 32) as u32,
                block_len, flags
            ],
            message_block
        }
    }

    /// Performs a round of Blake3, which performs 8 quarter rounds
    fn full_round(&mut self) {
        // Column rounds
        self.quarter_round(0, [0,4,8,12]);
        self.quarter_round(1, [1,5,9,13]);
        self.quarter_round(2, [2,6,10,14]);
        self.quarter_round(3, [3,7,11,15]);

        // Diagonal rounds
        self.quarter_round(4, [0,5,10,15]);
        self.quarter_round(5, [1,6,11,12]);
        self.quarter_round(6, [2,7,8,13]);
        self.quarter_round(7, [3,4,9,14]);
    }

    /// Denoted as G_i in the spec
    fn quarter_round(&mut self, i: Field, indexes: [Field; 4]) {
        let mut a = self.state[indexes[0]];
        let mut b = self.state[indexes[1]];
        let mut c = self.state[indexes[2]];
        let mut d = self.state[indexes[3]];

        a = a + b + self.message_block[2*i];
        d = d ^ a; right_rotation(&mut d, 16);
        c = c + d;
        b = b ^ c; right_rotation(&mut b, 12);
        a = a + b + self.message_block[2*i+1];
        d = d ^ a; right_rotation(&mut d, 8);
        c = c + d;
        b = b ^ c; right_rotation(&mut b, 7);

        self.state[indexes[0]] = a;
        self.state[indexes[1]] = b;
        self.state[indexes[2]] = c;
        self.state[indexes[3]] = d;
    }

    /// See Table 2 for the permutation schedule
    fn permute_message_block(&mut self) {
        let mut permuted = [0; 16];
        for i in 0..16 {
            permuted[i] = self.message_block[MSG_PERMUTATION[i]];
        }
        self.message_block = permuted;
    }
}

/// Performs the compression function specified by section 2.2
/// Words on 64 byte message blocks (16 32-bit words)
fn compress(input_chain: [u32; 8], counter: Field, block_len: u32, flags: u32, message_block: [u32; 16]) -> [u32; 16] {
    let mut state = Blake3State::new(
        input_chain,
        counter,
        block_len,
        flags,
        message_block
    );

    /// Perform 6 rounds of full_round and permute. Then do one more round without permuting
    for _i in 0..6 {
        state.full_round();
        state.permute_message_block();
    }
    state.full_round();

    for i in 0..8 {
        state.state[i] ^= state.state[i+8];
        state.state[i+8] ^= input_chain[i];
    }

    state.state
}

/// Performs a bitwise right rotation. NOT safe for n > 32
fn right_rotation(x: &mut u32, n: u32) {
    *x = ( (*x >> n) + (*x << (32-n)) );
}


#[test]
fn test_quarter_round() {

}