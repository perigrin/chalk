# ABOUTME: Loads chalk.so shared C library with RTLD_GLOBAL symbol visibility.
# ABOUTME: Must be required before any per-class XS wrapper .so files.
use 5.42.0;
use utf8;

package Chalk::Bootstrap::Runtime;
require DynaLoader;
require Config;

my $_loaded = false;

# Find chalk.so: check CHALK_SO_PATH env var first, then @INC
my $so;
if ($ENV{CHALK_SO_PATH} && -f $ENV{CHALK_SO_PATH}) {
    $so = $ENV{CHALK_SO_PATH};
} else {
    my $so_name = "chalk." . $Config::Config{dlext};
    for my $inc (@INC) {
        next if ref $inc;
        my $try = "$inc/auto/Chalk/Bootstrap/Runtime/$so_name";
        if (-f $try) { $so = $try; last; }
    }
}
die "Cannot find chalk.so (set CHALK_SO_PATH or install to \@INC)" unless $so;

# RTLD_GLOBAL (0x01 on Linux) makes C symbols visible to subsequently
# loaded shared libraries. This is how per-class .so files resolve
# boolean_is_zero() etc. without explicit linking.
my $flags = 0x01;  # RTLD_GLOBAL
my $libref = DynaLoader::dl_load_file($so, $flags)
    or die "Cannot load chalk.so ($so): " . DynaLoader::dl_error();

$_loaded = true;

sub loaded { $_loaded }

1;
