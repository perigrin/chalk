open(my $fh, "<", \ "l1\nl2\nl3") or die; my $first = <$fh>; my @rest = <$fh>; close $fh; chomp $first; print $first, scalar(@rest), $rest[-1], "\n";
