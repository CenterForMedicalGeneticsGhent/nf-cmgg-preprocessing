#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include {BAMTOOLS_SPLIT               } from "../../../modules/nf-core/modules/bamtools/split/main"
include {BIOBAMBAM_BAMMARKDUPLICATES2 } from "../../../modules/nf-core/modules/biobambam/bammarkduplicates2/main"
include {SAMTOOLS_MERGE               } from "../../../modules/nf-core/modules/samtools/merge/main"

workflow MARKDUP_PARALLEL {
    take:
        ch_input_bam    // [meta, [bam1,bam2,...]]

    main:
        ch_versions = Channel.empty()

        // merge the bams and split per chromosome or interval
        BAMTOOLS_SPLIT(ch_input_bam)
        ch_versions = ch_versions.mix(BAMTOOLS_SPLIT.out.versions)

        ch_split_bams = BAMTOOLS_SPLIT.out.bam.transpose().map {
            meta, bam ->
            new_meta = meta.clone()
            new_meta.id = bam.getBaseName()
            return [new_meta, bam]
        }

        // markduplicates
        BIOBAMBAM_BAMMARKDUPLICATES2(ch_split_bams)
        ch_versions = ch_versions.mix(BIOBAMBAM_BAMMARKDUPLICATES2.out.versions)

        ch_markdup_bam = BIOBAMBAM_BAMMARKDUPLICATES2.out.bam.map{
            meta, bam ->
            new_meta = meta.clone()
            new_meta.id = meta.samplename
            return [new_meta, bam]
        }.groupTuple()

        // re-merge bam
        SAMTOOLS_MERGE(ch_markdup_bam, [])
        ch_versions = ch_versions.mix(SAMTOOLS_MERGE.out.versions)

        // TODO re-merge metrics
        ch_metrics_merged = Channel.empty()

    emit:
        bam      = SAMTOOLS_MERGE.out.bam  // [meta, bam]
        metrics  = ch_metrics_merged       // [meta, metrics]
        versions = ch_versions             // versions
}
