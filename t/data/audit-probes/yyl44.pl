my $s = "abc"; my $r1 = $s =~ /^a/ && $s =~ /c$/ ? "both" : "no"; my $r2 = ($s !~ /z/) ? "noz" : "z"; my $r3 = $s =~ /B/i ? $& : ""; my ($r4) = $s =~ /(?:a)(.)/; print "$r1$r2$r3$r4\n";
