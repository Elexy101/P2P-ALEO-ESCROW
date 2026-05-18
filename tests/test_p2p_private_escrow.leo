// The 'test_p2p_private_escrow' test program.
import p2p_private_escrow.aleo;
program test_p2p_private_escrow.aleo {
    @test
    @should_fail
    fn test_main_fails() {
        let result: u32 = p2p_private_escrow.aleo::main(2u32, 3u32);
        assert_eq(result, 3u32);
    }

    @noupgrade
    constructor() {}
}
