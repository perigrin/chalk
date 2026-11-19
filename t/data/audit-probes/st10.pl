my %h; my $a = %h ? 1 : 0; $h{k} = 1; my $b = scalar(%h) ? 1 : 0; print "$a$b\n";
