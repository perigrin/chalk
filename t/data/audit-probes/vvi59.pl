my $s = "abc"; my @l = ("$s", $s =~ s/b/z/, "$s"); print "@l\n";
