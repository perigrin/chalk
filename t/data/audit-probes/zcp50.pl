my @a=(1,2); my $r=\@a; my @c=@$r; $r=[9]; print "@c\n";
