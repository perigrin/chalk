our $g = 1; my $ok = eval { for my $i (1..3) { local $g = $i; die "at$i\n" if $i == 2 } 1 }; print $@, $g, "\n";
