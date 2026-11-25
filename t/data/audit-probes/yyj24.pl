package P; sub who { __PACKAGE__ } package Q; sub who { __PACKAGE__ . P::who() } package main; print Q::who(), __PACKAGE__, "\n";
