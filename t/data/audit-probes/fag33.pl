my @a=(1,2); my $r=\@a; my @c=@$r; push @a,3; print scalar(@c),"\n";
