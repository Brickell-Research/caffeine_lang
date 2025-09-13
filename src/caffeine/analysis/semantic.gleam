//// We perform the following semantic analysis against the intermediate representation of the organization.
//// (1) Ensure that all services are defined in the service definitions section.
//// (2) Ensure that all sli types are defined in the sli types section.
//// (3) Ensure that all SLOs are referencing valid SLI types for their service.
//// (4) Ensure that the SLO threshold is between 0 and 100.
//// (5) Ensure that all filters are valid for the SLI type.
//// (7) Ensure no duplicate service names or duplicate SLOs for a single service and team combination.
//// (8) Ensure that all services, sli types, and sli filters in the specification are unique.
//// (9) Ensure that all filters within the SLOs are the correct types for the SLI type's filters.
//// (10) For every required true sli filter, ensure that it is present in the SLO.
//// (11) For every filter within SLO instantiation, if unknown, reject it.
//// (12) Perform query template hygiene:
////    (12.1) Ensure that the query template is valid and not empty.
////    (12.2) Every template variable in the query template must be present in the filters of the SLI type.
//// (13) Warn on unused sli types, sli filters, and services.
//// (14) Normalize team names, service names, sli type names, sli filter names, and sli filter attribute names to lowercase.

