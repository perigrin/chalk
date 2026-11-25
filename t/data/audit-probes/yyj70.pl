my @a=(1,2); my $r=\@a; my @b=@$r; push @$r, 3; my $s=$r; push @$s, 4; print scalar(@a), scalar(@b), $r == $s ? "same" : "diff", "\n";
