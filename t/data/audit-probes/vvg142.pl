my $c = \&main::id; sub id { "i@_" } print $c->(1), &$c(2), &{$c}(3), "\n";
