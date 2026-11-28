my $s = "abc"; my %h = (k => $s); $h{k} =~ s/a/z/; print "$s$h{k}\n";
