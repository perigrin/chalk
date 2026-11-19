our @ISA; package P; sub hi { "P" } package main; my $a = main->can("hi") ? 1 : 0; push @ISA, "P"; my $b = main->can("hi") ? 1 : 0; print "$a$b\n";
