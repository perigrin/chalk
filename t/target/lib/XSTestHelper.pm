package XSTestHelper;
# ABOUTME: Test helper for XS compilation testing
# ABOUTME: Provides utilities to generate Makefile.PL, write XS files, and compile them

use strict;
use warnings;
use File::Spec;
use Cwd qw(getcwd);

our $VERSION = '0.01';

=head1 NAME

XSTestHelper - Test helper for XS compilation

=head1 SYNOPSIS

    use XSTestHelper;

    my $dir = tempdir(CLEANUP => 1);
    XSTestHelper::generate_makefile_pl($dir, 'MyModule');
    XSTestHelper::write_xs_file($dir, 'MyModule', $xs_code);
    my $result = XSTestHelper::compile_xs($dir);

=head1 FUNCTIONS

=head2 generate_makefile_pl($dir, $module_name)

Generates a Makefile.PL in the specified directory for the given module name.
Returns true on success, dies on failure.

=cut

sub generate_makefile_pl {
    my ($dir, $module_name) = @_;

    die "Directory not specified" unless defined $dir;
    die "Module name not specified" unless defined $module_name;
    die "Directory does not exist: $dir" unless -d $dir;

    my $makefile_pl = File::Spec->catfile($dir, 'Makefile.PL');

    my $content = <<"MAKEFILE_PL";
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME => '$module_name',
    VERSION => '0.01',
);
MAKEFILE_PL

    open my $fh, '>', $makefile_pl
        or die "Cannot write to $makefile_pl: $!";
    print $fh $content;
    close $fh;

    return 1;
}

=head2 write_xs_file($dir, $module_name, $xs_code)

Writes an XS file with the given code to the specified directory.
Returns true on success, dies on failure.

=cut

sub write_xs_file {
    my ($dir, $module_name, $xs_code) = @_;

    die "Directory not specified" unless defined $dir;
    die "Module name not specified" unless defined $module_name;
    die "XS code not specified" unless defined $xs_code;
    die "Directory does not exist: $dir" unless -d $dir;

    my $xs_file = File::Spec->catfile($dir, "$module_name.xs");

    open my $fh, '>', $xs_file
        or die "Cannot write to $xs_file: $!";
    print $fh $xs_code;
    close $fh;

    return 1;
}

=head2 compile_xs($dir)

Compiles the XS module in the specified directory by running:
  perl Makefile.PL && make

Returns a hashref with:
  - success: boolean indicating if compilation succeeded
  - stdout: standard output from the commands
  - stderr: standard error from the commands
  - exit_code: exit code from make

=cut

sub compile_xs {
    my ($dir) = @_;

    die "Directory not specified" unless defined $dir;
    die "Directory does not exist: $dir" unless -d $dir;

    my $makefile_pl = File::Spec->catfile($dir, 'Makefile.PL');
    die "Makefile.PL not found in $dir" unless -f $makefile_pl;

    # Save current directory
    my $orig_dir = getcwd();

    # Change to target directory
    chdir $dir or die "Cannot chdir to $dir: $!";

    my $stdout = '';
    my $stderr = '';
    my $exit_code = 0;

    eval {
        # Run perl Makefile.PL
        my $makefile_cmd = "$^X Makefile.PL 2>&1";
        my $makefile_output = `$makefile_cmd`;
        $stdout .= $makefile_output;

        if ($? != 0) {
            $stderr .= "Makefile.PL failed with exit code: " . ($? >> 8) . "\n";
            $stderr .= $makefile_output;
            $exit_code = $? >> 8;
            die "Makefile.PL failed";
        }

        # Run make
        my $make_cmd = "make 2>&1";
        my $make_output = `$make_cmd`;
        $stdout .= $make_output;

        if ($? != 0) {
            $stderr .= "make failed with exit code: " . ($? >> 8) . "\n";
            $stderr .= $make_output;
            $exit_code = $? >> 8;
            die "make failed";
        }
    };

    my $error = $@;

    # Restore original directory
    chdir $orig_dir or die "Cannot chdir back to $orig_dir: $!";

    if ($error) {
        return {
            success => 0,
            stdout => $stdout,
            stderr => $stderr,
            exit_code => $exit_code || 1,
        };
    }

    return {
        success => 1,
        stdout => $stdout,
        stderr => $stderr,
        exit_code => 0,
    };
}

1;

__END__

=head1 AUTHOR

Chalk Project

=head1 LICENSE

Same as Perl itself.

=cut
