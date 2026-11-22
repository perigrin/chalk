our $g=0; sub bump { no strict 'refs'; ${"main::g"} += 10 } for (1..3){ $g=$g+1; bump() } print "$g\n";
