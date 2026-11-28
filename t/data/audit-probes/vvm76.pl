our $x = 1; sub ref { \$x } { local $x = 2; ${ref()} = 5; print $x } print "$x\n";
