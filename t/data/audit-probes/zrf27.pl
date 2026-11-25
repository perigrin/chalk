sub set { my $r=shift; $$r=5 } my %h; set(\$h{k}); print "$h{k}\n";
