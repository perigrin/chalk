my @a=(1,2); my @b=@a; my $r=\@a; push @$r, 3; print "@b\n";
