my $ok = "abc" =~ /b/; my $no = "abc" =~ /z/; my @e = "abc" =~ /z/; my @o = "abc" =~ /b/; my @c = "abc" =~ /(b)(c)/; print "$ok", defined $no ? "[$no]" : "u", scalar(@e), "@o@c\n";
