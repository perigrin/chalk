my $str = "a b\tc\nd"; my @w = split ' ', $str; my @x = split / /, $str; my @l = split /\n/, "a\n\nb\n\n"; print scalar(@w), scalar(@x), scalar(@l), "\n";
