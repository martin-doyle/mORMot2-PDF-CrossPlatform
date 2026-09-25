// conditionals shared by the test units - include after mormot.defines.inc

// the TCanvas bridge (TPdfDocumentVcl, TPdfVclCanvas) and the report engine
// on top of it: LCL only until they exist on Delphi (roadmap R-20) - then
// define it here for Delphi too, and every suite that needs them comes back
{$ifdef FPC}
  {$define PDF_HASVCLCANVAS}
{$endif FPC}
