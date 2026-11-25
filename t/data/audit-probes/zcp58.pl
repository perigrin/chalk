my @a=(1,2); my $r=\@a; my @c=@a; shift @$r; print "@c\n";
