my $s = "abc"; $s =~ /(?<n>a)/; my @l = ($+{n}, $s =~ /(?<n>b)/); print "@l\n";
