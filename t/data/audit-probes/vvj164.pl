my @a = (1,2,3); sub ret { return (@a, 4) } my $l = ret(); my $c = () = ret(); print "$l$c\n";
