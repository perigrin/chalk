sub f { for (@_) { return $_ if $_ > 1 } "none" } $_ = "t"; print f(1,2,3), $_, "\n";
