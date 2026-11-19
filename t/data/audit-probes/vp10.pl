my %h; my $r = ($h{a} //= 5) + ($h{a} ||= 7); print "$r $h{a}\n";
