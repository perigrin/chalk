my $r=[1,2]; my @c=@$r; @$r=(); print "@c|", scalar(@$r), "\n";
