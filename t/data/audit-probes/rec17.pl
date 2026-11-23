our $g=1; sub f { local $g=2; my $z=shift; 1/$z } f(0) if @ARGV; eval { f(0); }; print "$g $@" ;
