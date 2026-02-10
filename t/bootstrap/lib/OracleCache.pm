# ABOUTME: Caches B::Concise -exec output keyed by SHA256 of source file content.
# ABOUTME: Eliminates redundant perl subprocess calls when source files haven't changed.
use 5.42.0;
use utf8;

package OracleCache;

use Exporter 'import';
our @EXPORT_OK = qw(get_or_generate cache_dir);

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);

my $CACHE_DIR = 't/bootstrap/.oracle-cache';

# Returns the cache directory path
sub cache_dir {
    return $CACHE_DIR;
}

# Returns B::Concise -exec output for a file, using cache when possible.
# On cache hit: reads cached output (keyed by SHA256 of file content).
# On cache miss: runs perl -MO=Concise,-exec, writes to cache, returns output.
sub get_or_generate($file) {
    my $content = do {
        open my $fh, '<:raw', $file or die "Cannot read $file: $!";
        local $/;
        <$fh>;
    };

    my $sha = sha256_hex($content);
    my $cache_file = "$CACHE_DIR/$sha.concise";

    if (-f $cache_file) {
        open my $fh, '<:raw', $cache_file or die "Cannot read cache $cache_file: $!";
        local $/;
        return <$fh>;
    }

    # Cache miss — run B::Concise
    make_path($CACHE_DIR) unless -d $CACHE_DIR;
    my $output = `perl -Ilib -MO=Concise,-exec $file 2>&1`;

    # Write to cache
    open my $fh, '>:raw', $cache_file or die "Cannot write cache $cache_file: $!";
    print $fh $output;
    close $fh;

    return $output;
}

1;
