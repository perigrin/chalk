sub f { for my $i (1..3) { eval { return "r$i" if $i == 2 }; } "end" } print f(), "\n";
