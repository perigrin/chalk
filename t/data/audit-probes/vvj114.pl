my %h = (a=>1); my $e = exists $h{a}; my $f = exists $h{b}; my $v = $h{b}; print $e ? "t" : "f", $f ? "t" : "f", exists $h{b} ? "t" : "f", "\n";
