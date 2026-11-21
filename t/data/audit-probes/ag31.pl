our %h; sub f { $h{n} = 7; 0 } print $h{n} // "u", f(), $h{n}, "\n";
