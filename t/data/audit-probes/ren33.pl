my %h=(a=>1); my $e=\$h{a}; my %c=%h; $$e=9; print "$c{a}\n";
