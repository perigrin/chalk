my @a=(1,2,3); my $r=\@a; my @c=@$r; @$r=(); print "@c|@a\n";
