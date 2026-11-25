our $x=1; sub r { \$x } my $o=$x; ${r()}=5; print "$o$x\n";
