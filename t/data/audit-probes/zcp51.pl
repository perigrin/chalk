my @a=(1,2); my @c=@a; my $r=\@c; push @$r,3; print scalar(@a), scalar(@c), "\n";
