our $g=1; if (@ARGV == 0) { eval { local $g = 2; 1 } } print "$g\n";
