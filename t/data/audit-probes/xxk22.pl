my %h = (k => "abc"); $h{k} =~ s/b/B/; $h{k} =~ tr/a/A/; (my $c = $h{k}) =~ s/c/C/; print "$h{k}$c\n";
