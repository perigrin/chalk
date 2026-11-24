my %h=(a=>1); my $l=\$h{a}; %h=(a=>2); $$l=9; print "$h{a}\n";
