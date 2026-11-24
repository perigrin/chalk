my %h=(a=>1); sub n { delete $h{a} } my $e = exists $h{a}; n(); my $f = exists $h{a}; print $e?1:0, $f?1:0, "\n";
