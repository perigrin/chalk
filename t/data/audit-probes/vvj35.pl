my @a = (1,2,3,4); my @e = grep { !($_ & 1) } @a; my $c = grep { $_ > 1 } @a; print "@e$c\n";
