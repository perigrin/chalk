my $s = "abc"; if ($s =~ /(a)/) { for my $w ("x") { $w =~ /(.)/ } print $1 } print "\n";
