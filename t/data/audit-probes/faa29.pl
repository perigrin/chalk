my @a=(1,2); my @b=(3,4); my $r = (@ARGV ? \@a : \@b); push @$r,5; print "@a|@b\n";
