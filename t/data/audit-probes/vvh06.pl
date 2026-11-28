my $x = 1; my $r = eval { die "z\n"; 7 }; print defined $r ? "d" : "u", "$@";
