our @a = (1,2,3); our @b; my $n = (@b = @a); push @b, 4; print "$n@a|@b\n";
