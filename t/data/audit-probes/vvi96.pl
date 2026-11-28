my $s = "abc"; $s =~ /(a)(b)/; my ($p, $q) = ($1, $2); $s =~ /(c)/; print "$p$q$1", defined $2 ? "d" : "u", "\n";
