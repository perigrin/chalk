my %h = (a=>1, b=>2); sub f { $_ *= 10 for @_ } f(values %h); print "$h{a} $h{b}\n";
