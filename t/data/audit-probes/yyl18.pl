my $s = "ab"; $s =~ s/(a)(x)?b/[$1][@{[ defined $2 ? "d" : "u" ]}]/; my $t = "b"; $t =~ /(a)|(b)/; print $s, defined $1 ? "d" : "u", $2, "\n";
