// RUN: iree-opt %s --pass-pipeline='builtin.module(func.func(iree-gpu-pack-to-intrinsics, canonicalize, cse))' --split-input-file | FileCheck %s

#config = #iree_gpu.lowering_config<{mma_kind = #iree_gpu.mma_layout<MFMA_F32_32x32x8_F16>}>
module {
  func.func @matmul_32x32x8(%a: tensor<64x64xf16>, %b: tensor<64x64xf16>, %c: tensor<64x64xf32>) -> tensor<64x64xf32> {
    %mm = linalg.matmul {lowering_config = #config} ins(%a, %b : tensor<64x64xf16>, tensor<64x64xf16>) outs(%c : tensor<64x64xf32>) -> tensor<64x64xf32>
    return %mm : tensor<64x64xf32>
  }
}

// CHECK-LABEL: func.func @matmul_32x32x8
//  CHECK-SAME:   %[[A:[A-Za-z0-9]+]]: tensor<64x64xf16>
//  CHECK-SAME:   %[[B:[A-Za-z0-9]+]]: tensor<64x64xf16>
//  CHECK-SAME:   %[[C:[A-Za-z0-9]+]]: tensor<64x64xf32>
//   CHECK-DAG:   %[[A_PACK:.+]] = tensor.pack %[[A]] inner_dims_pos = [0, 1] inner_tiles = [32, 8]
//   CHECK-DAG:   %[[B_PACK:.+]] = tensor.pack %[[B]] inner_dims_pos = [1, 0] inner_tiles = [32, 8]
//   CHECK-DAG:   %[[C_PACK:.+]] = tensor.pack %[[C]] inner_dims_pos = [0, 1] inner_tiles = [32, 32]
//       CHECK:   %[[PACKED_MM:.+]] = linalg.generic
//  CHECK-SAME:     ins(%[[A_PACK]], %[[B_PACK]] : tensor<2x8x32x8xf16>, tensor<8x2x32x8xf16>)
//  CHECK-SAME:     outs(%[[C_PACK]] : tensor<2x2x32x32xf32>)
//  CHECK-SAME:     lowering_config = #iree_gpu.lowering_config<{mma_kind = #iree_gpu.mma_layout<MFMA_F32_32x32x8_F16>}>

// -----

#map = affine_map<(d0, d1, d2, d3, d4) -> (d1, d3, d4)>
#map1 = affine_map<(d0, d1, d2, d3, d4) -> (d2, d0, d3, d4)>
#map2 = affine_map<(d0, d1, d2, d3, d4) -> (d0, d1, d2)>
module {
  func.func @matmul_16x16x16(%a: tensor<?x?x?xf16>, %b: tensor<?x?x?x?xf16>, %c: tensor<?x?x?xf32>) -> tensor<?x?x?xf32> {
    %mm = linalg.generic {
      indexing_maps = [#map, #map1, #map2],
      iterator_types = ["parallel", "parallel", "parallel", "reduction", "reduction"]
    } ins(%a, %b : tensor<?x?x?xf16>, tensor<?x?x?x?xf16>)
    outs(%c : tensor<?x?x?xf32>) attrs =  {
      lowering_config = #iree_gpu.lowering_config<{mma_kind = #iree_gpu.mma_layout<MFMA_F32_16x16x16_F16>}>
    } {
    ^bb0(%in: f16, %in_2: f16, %out: f32):
      %4 = arith.extf %in : f16 to f32
      %5 = arith.extf %in_2 : f16 to f32
      %6 = arith.mulf %4, %5 : f32
      %7 = arith.addf %out, %6 : f32
      linalg.yield %7 : f32
    } -> tensor<?x?x?xf32>
    return %mm : tensor<?x?x?xf32>
  }
}

// CHECK: #[[$MAP:.+]] = affine_map<(d0, d1, d2, d3, d4, d5, d6, d7) -> (d1, d3, d4, d5, d7)>
// CHECK: #[[$MAP1:.+]] = affine_map<(d0, d1, d2, d3, d4, d5, d6, d7) -> (d2, d0, d3, d4, d6, d7)>
// CHECK: #[[$MAP2:.+]] = affine_map<(d0, d1, d2, d3, d4, d5, d6, d7) -> (d0, d1, d2, d5, d6)>

// CHECK-LABEL: func.func @matmul_16x16x16
//       CHECK:   %[[PACKED_MM:.+]] = linalg.generic
//  CHECK-SAME:     indexing_maps = [#[[$MAP]], #[[$MAP1]], #[[$MAP2]]]
//  CHECK-SAME:     ins({{.*}} : tensor<?x?x?x16x16xf16>, tensor<?x?x?x?x16x16xf16>)
//  CHECK-SAME:     outs({{.*}} : tensor<?x?x?x16x16xf32>)
//  CHECK-SAME:     lowering_config = #iree_gpu.lowering_config<{mma_kind = #iree_gpu.mma_layout<MFMA_F32_16x16x16_F16>}>
