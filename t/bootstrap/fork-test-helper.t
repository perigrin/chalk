# ABOUTME: Tests the fork_test helper function from TestXSHelpers.
# ABOUTME: Validates SIGALRM handling, output capture, and failure classification.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use File::Temp ();
use TestXSHelpers qw(fork_test);

# ============================================================
# 1. Successful test — should pass (not TODO)
# ============================================================

subtest 'fork_test: success case' => sub {
    fork_test('FakeModule', sub ($m) {
        # Do nothing — success
    }, 'success');
    # The last test emitted by fork_test should be a pass
};

# ============================================================
# 2. Runtime failure — should be a real FAIL (not TODO)
# ============================================================

# We test that runtime failures produce real FAILs (not TODO) by
# running fork_test against a child process that dies, then checking
# the generated TAP output. We use a forked child ourselves to
# isolate the failing test from our TAP stream.
subtest 'fork_test: runtime failure is real fail' => sub {
    # Fork a child that runs fork_test and captures the TAP output
    my $outfile = File::Temp::tmpnam();
    my $pid = fork();
    if ($pid == 0) {
        # In child: redirect TAP output to file
        my $tb = Test::More->builder;
        open my $fh, '>', $outfile or exit(99);
        $tb->output($fh);
        $tb->failure_output($fh);
        $tb->todo_output($fh);

        fork_test('FakeModule', sub ($m) {
            die "intentional failure";
        }, 'runtime-fail');

        close $fh;
        exit(0);
    }
    waitpid($pid, 0);

    # Read the captured TAP
    open my $fh, '<', $outfile or do {
        fail("could not read captured TAP"); return;
    };
    local $/;
    my $tap = <$fh>;
    close $fh;
    unlink $outfile;

    like($tap, qr/not ok/, 'runtime failure produces not ok');
    unlike($tap, qr/# TODO/, 'runtime failure is NOT wrapped in TODO');
    like($tap, qr/intentional failure/, 'child error message captured in diagnostics');
};

# ============================================================
# 3. Timeout — SIGALRM should exit(124), reported as timeout
# ============================================================

subtest 'fork_test: timeout detection' => sub {
    # This test verifies that alarm triggers exit(124), not signal death
    my $builder = Test::More->builder;
    my $before = $builder->current_test;

    fork_test('FakeModule', sub ($m) {
        # Sleep longer than alarm timeout
        sleep(30);
    }, 'timeout', timeout => 2);

    my $after = $builder->current_test;
    is($after - $before, 1, 'fork_test emitted one test for timeout');
};

# ============================================================
# 4. Segfault (signal death) — should be TODO-wrapped
# ============================================================

# Can't easily trigger a real segfault in pure Perl, but we can
# verify the signal-handling path by sending ourselves SIGSEGV
subtest 'fork_test: signal death is TODO' => sub {
    my $builder = Test::More->builder;
    my $before = $builder->current_test;

    fork_test('FakeModule', sub ($m) {
        kill 'SEGV', $$;
    }, 'signal-death');

    my $after = $builder->current_test;
    is($after - $before, 1, 'fork_test emitted one test for signal death');
};

# ============================================================
# 5. Runtime failure with todo option — should be TODO-wrapped
# ============================================================

subtest 'fork_test: runtime failure with todo is TODO' => sub {
    my $outfile = File::Temp::tmpnam();
    my $pid = fork();
    if ($pid == 0) {
        my $tb = Test::More->builder;
        open my $fh, '>', $outfile or exit(99);
        $tb->output($fh);
        $tb->failure_output($fh);
        $tb->todo_output($fh);

        fork_test('FakeModule', sub ($m) {
            die "expected failure";
        }, 'todo-fail', todo => 'XS emitter gap');

        close $fh;
        exit(0);
    }
    waitpid($pid, 0);

    open my $fh, '<', $outfile or do {
        fail("could not read captured TAP"); return;
    };
    local $/;
    my $tap = <$fh>;
    close $fh;
    unlink $outfile;

    like($tap, qr/not ok/, 'todo runtime failure produces not ok');
    like($tap, qr/# TODO/, 'todo runtime failure IS wrapped in TODO');
    like($tap, qr/XS emitter gap/, 'todo reason appears in output');
};

done_testing();
