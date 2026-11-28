sub mx { my $m = shift; for (@_) { $m = $_ if $_ > $m } $m } print mx(3, 9, 2), "\n";
