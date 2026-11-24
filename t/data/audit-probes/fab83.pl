my $n=0; my $z=0; sub cnt { $n++; 1 } my $r = eval { cnt() / $z }; print "$n\n";
