my @h=(1); for my $i (1..3) { my @c=@h; $c[0]+=$i; push @h, $i; print scalar(@c), ":$c[0] " } print "@h\n";
