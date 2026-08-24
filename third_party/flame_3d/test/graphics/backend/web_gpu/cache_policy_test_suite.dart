import 'package:flame_3d/src/graphics/backend/web_gpu/cache_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void runWebGpuCachePolicyTests() {
  group('WebGpuBindCachePolicy', () {
    test('complete ordered bind key controls every cache hit', () {
      final policy = WebGpuBindCachePolicy.forTesting(enabled: true)
        ..beginFrame();
      final pipeline = Object();
      final layout = Object();
      final buffer = Object();
      final view = Object();
      final sampler = Object();
      var creates = 0;

      Object resolve({
        Object? pipelineToken,
        Object? layoutToken,
        int group = 1,
        int binding = 2,
        Object? bufferToken,
        int offset = 256,
        int size = 64,
        int revision = 7,
        int textureBinding = 0,
        int samplerBinding = 1,
        Object? viewToken,
        Object? samplerToken,
        bool reverse = false,
      }) {
        final uniform = WebGpuUniformBindKey(
          binding: binding,
          bufferToken: bufferToken ?? buffer,
          offset: offset,
          size: size,
          revision: revision,
        );
        final texture = WebGpuTextureBindKey(
          binding: textureBinding,
          samplerBinding: samplerBinding,
          viewToken: viewToken ?? view,
          samplerToken: samplerToken ?? sampler,
        );
        return policy.resolveBindGroup(
          pipelineToken: pipelineToken ?? pipeline,
          layoutToken: layoutToken ?? layout,
          group: group,
          resources: reverse ? [uniform, texture] : [texture, uniform],
          create: () {
            creates++;
            return Object();
          },
        );
      }

      final baseline = resolve();
      expect(resolve(), same(baseline));
      expect(creates, 1);

      for (final changed in <Object Function()>[
        () => resolve(pipelineToken: Object()),
        () => resolve(layoutToken: Object()),
        () => resolve(binding: 3),
        () => resolve(bufferToken: Object()),
        () => resolve(offset: 512),
        () => resolve(size: 32),
        () => resolve(revision: 8),
        () => resolve(textureBinding: 4),
        () => resolve(samplerBinding: 5),
        () => resolve(viewToken: Object()),
        () => resolve(samplerToken: Object()),
        () => resolve(reverse: true),
      ]) {
        expect(changed(), isNot(same(baseline)));
      }

      final firstOtherGroup = resolve(group: 0);
      expect(resolve(group: 0), isNot(same(firstOtherGroup)));
      policy.endFrame();

      expect(policy.lastCounters.bindGroupHits, 1);
      expect(policy.lastCounters.bindGroupMisses, 13);
    });

    test('fallback buffer, view, and sampler identities are key material', () {
      final policy = WebGpuBindCachePolicy.forTesting(enabled: true)
        ..beginFrame();
      final pipeline = Object();
      final layout = Object();
      final fallbackBuffer = Object();
      final fallbackView = Object();
      final fallbackSampler = Object();

      Object resolve({Object? buffer, Object? view, Object? sampler}) {
        return policy.resolveBindGroup(
          pipelineToken: pipeline,
          layoutToken: layout,
          group: 1,
          resources: [
            WebGpuTextureBindKey(
              binding: 0,
              samplerBinding: 1,
              viewToken: view ?? fallbackView,
              samplerToken: sampler ?? fallbackSampler,
            ),
            WebGpuUniformBindKey(
              binding: 2,
              bufferToken: buffer ?? fallbackBuffer,
              offset: 0,
              size: 64,
              revision: 0,
            ),
          ],
          create: Object.new,
        );
      }

      final baseline = resolve();
      expect(resolve(), same(baseline));
      expect(resolve(buffer: Object()), isNot(same(baseline)));
      expect(resolve(view: Object()), isNot(same(baseline)));
      expect(resolve(sampler: Object()), isNot(same(baseline)));
      policy.endFrame();
    });

    test(
      'sampled texture view is retained for exactly one resource lifetime',
      () {
        final policy = WebGpuBindCachePolicy.forTesting(enabled: true);
        final firstLifetime = WebGpuTextureViewLifetime<Object>();
        final secondLifetime = WebGpuTextureViewLifetime<Object>();
        var createCount = 0;

        Object resolve(WebGpuTextureViewLifetime<Object> lifetime) {
          return policy.resolveTextureView(
            group: 1,
            lifetime: lifetime,
            create: () {
              createCount++;
              return Object();
            },
          );
        }

        policy.beginFrame();
        final firstView = resolve(firstLifetime);
        expect(resolve(firstLifetime), same(firstView));
        final recreatedTextureView = resolve(secondLifetime);
        expect(recreatedTextureView, isNot(same(firstView)));
        policy.endFrame();
        expect(createCount, 2);
        expect(policy.lastCounters.textureViewHits, 1);
        expect(policy.lastCounters.textureViewMisses, 2);

        policy.beginFrame();
        expect(resolve(firstLifetime), same(firstView));
        policy.endFrame();
        expect(createCount, 2);
        expect(policy.lastCounters.textureViewHits, 1);
        expect(policy.lastCounters.textureViewMisses, 0);
      },
    );

    test('four frames never reuse uploads or bind groups across rotation', () {
      final policy = WebGpuBindCachePolicy.forTesting(enabled: true);
      final bindingIdentity = Object();
      final pipeline = Object();
      final layout = Object();
      final rotatingBuffers = [Object(), Object(), Object()];
      final allocations = <WebGpuUniformAllocation>[];
      final bindGroups = <Object>[];
      var uploadCalls = 0;
      var bindGroupCreates = 0;

      for (var frame = 0; frame < 4; frame++) {
        policy.beginFrame();
        WebGpuUniformAllocation upload() {
          uploadCalls++;
          return WebGpuUniformAllocation(
            bufferToken: rotatingBuffers[frame % rotatingBuffers.length],
            offset: 0,
            size: 64,
            revision: 4,
          );
        }

        final allocation = policy.resolveUniformUpload(
          group: 1,
          binding: 2,
          bindingIdentity: bindingIdentity,
          revision: 4,
          size: 64,
          upload: upload,
        );
        expect(
          policy.resolveUniformUpload(
            group: 1,
            binding: 2,
            bindingIdentity: bindingIdentity,
            revision: 4,
            size: 64,
            upload: upload,
          ),
          same(allocation),
        );

        Object createBindGroup() {
          bindGroupCreates++;
          return Object();
        }

        final resources = [
          WebGpuUniformBindKey(
            binding: 2,
            bufferToken: allocation.bufferToken,
            offset: allocation.offset,
            size: allocation.size,
            revision: allocation.revision,
          ),
        ];
        final bindGroup = policy.resolveBindGroup(
          pipelineToken: pipeline,
          layoutToken: layout,
          group: 1,
          resources: resources,
          create: createBindGroup,
        );
        expect(
          policy.resolveBindGroup(
            pipelineToken: pipeline,
            layoutToken: layout,
            group: 1,
            resources: resources,
            create: createBindGroup,
          ),
          same(bindGroup),
        );
        policy.endFrame();

        allocations.add(allocation);
        bindGroups.add(bindGroup);
        expect(policy.lastCounters.uniformUploadHits, 1);
        expect(policy.lastCounters.uniformUploadMisses, 1);
        expect(policy.lastCounters.bindGroupHits, 1);
        expect(policy.lastCounters.bindGroupMisses, 1);
      }

      expect(uploadCalls, 4);
      expect(bindGroupCreates, 4);
      expect(allocations[3].bufferToken, same(allocations[0].bufferToken));
      expect(allocations[3], isNot(same(allocations[0])));
      expect(bindGroups.toSet(), hasLength(4));
    });

    test('disabled sequence matches upstream uploads and bind creation', () {
      List<String> run({required bool enabled}) {
        final policy = WebGpuBindCachePolicy.forTesting(enabled: enabled)
          ..beginFrame();
        final textureLifetime = WebGpuTextureViewLifetime<Object>();
        final materialIdentity = Object();
        final cameraIdentity = Object();
        final pipeline = Object();
        final layout = Object();
        final events = <String>[];

        for (var draw = 0; draw < 2; draw++) {
          final view = policy.resolveTextureView(
            group: 1,
            lifetime: textureLifetime,
            create: () {
              events.add('createView:$draw');
              return Object();
            },
          );
          WebGpuUniformAllocation upload(String name, Object identity) {
            return policy.resolveUniformUpload(
              group: 1,
              binding: name == 'material' ? 2 : 3,
              bindingIdentity: identity,
              revision: 1,
              size: name == 'material' ? 64 : 16,
              upload: () {
                events.add('upload:$name:$draw');
                return WebGpuUniformAllocation(
                  bufferToken: Object(),
                  offset: name == 'material' ? 0 : 256,
                  size: name == 'material' ? 64 : 16,
                  revision: 1,
                );
              },
            );
          }

          final material = upload('material', materialIdentity);
          final camera = upload('camera', cameraIdentity);
          policy.resolveBindGroup(
            pipelineToken: pipeline,
            layoutToken: layout,
            group: 1,
            resources: [
              WebGpuTextureBindKey(
                binding: 0,
                samplerBinding: 1,
                viewToken: view,
                samplerToken: const _Token('sampler'),
              ),
              WebGpuUniformBindKey(
                binding: 2,
                bufferToken: material.bufferToken,
                offset: material.offset,
                size: material.size,
                revision: material.revision,
              ),
              WebGpuUniformBindKey(
                binding: 3,
                bufferToken: camera.bufferToken,
                offset: camera.offset,
                size: camera.size,
                revision: camera.revision,
              ),
            ],
            create: () {
              events.add('bindGroup:$draw');
              return Object();
            },
          );
        }
        policy.endFrame();
        return events;
      }

      expect(run(enabled: true), [
        'createView:0',
        'upload:material:0',
        'upload:camera:0',
        'bindGroup:0',
      ]);
      expect(run(enabled: false), [
        'createView:0',
        'upload:material:0',
        'upload:camera:0',
        'bindGroup:0',
        'createView:1',
        'upload:material:1',
        'upload:camera:1',
        'bindGroup:1',
      ]);
    });

    test('group zero stays uncached and outside group-one counters', () {
      final policy = WebGpuBindCachePolicy.forTesting(enabled: true)
        ..beginFrame();
      final lifetime = WebGpuTextureViewLifetime<Object>();
      var viewCreates = 0;
      var uploads = 0;
      var bindGroups = 0;

      for (var draw = 0; draw < 2; draw++) {
        policy.resolveTextureView(
          group: 0,
          lifetime: lifetime,
          create: () {
            viewCreates++;
            return Object();
          },
        );
        policy.resolveUniformUpload(
          group: 0,
          binding: 1,
          bindingIdentity: const _Token('vertex'),
          revision: 1,
          size: 192,
          upload: () {
            uploads++;
            return WebGpuUniformAllocation(
              bufferToken: Object(),
              offset: 0,
              size: 192,
              revision: 1,
            );
          },
        );
        policy.resolveBindGroup(
          pipelineToken: const _Token('pipeline'),
          layoutToken: const _Token('layout'),
          group: 0,
          resources: const [],
          create: () {
            bindGroups++;
            return Object();
          },
        );
      }
      policy.endFrame();

      expect((viewCreates, uploads, bindGroups), (2, 2, 2));
      expect(policy.lastCounters.textureViewHits, 0);
      expect(policy.lastCounters.textureViewMisses, 0);
      expect(policy.lastCounters.uniformUploadHits, 0);
      expect(policy.lastCounters.uniformUploadMisses, 0);
      expect(policy.lastCounters.bindGroupHits, 0);
      expect(policy.lastCounters.bindGroupMisses, 0);
    });

    test('counter growth saturates at the configured test bound', () {
      final policy = WebGpuBindCachePolicy.forTesting(
        enabled: false,
        counterLimit: 2,
      )..beginFrame();
      final lifetime = WebGpuTextureViewLifetime<Object>();

      for (var i = 0; i < 5; i++) {
        policy.resolveTextureView(
          group: 1,
          lifetime: lifetime,
          create: Object.new,
        );
        policy.resolveUniformUpload(
          group: 1,
          binding: 2,
          bindingIdentity: Object(),
          revision: i,
          size: 4,
          upload: () => WebGpuUniformAllocation(
            bufferToken: Object(),
            offset: 0,
            size: 4,
            revision: i,
          ),
        );
        policy.resolveBindGroup(
          pipelineToken: Object(),
          layoutToken: Object(),
          group: 1,
          resources: const [],
          create: Object.new,
        );
      }
      policy.endFrame();

      expect(policy.lastCounters.textureViewMisses, 2);
      expect(policy.lastCounters.uniformUploadMisses, 2);
      expect(policy.lastCounters.bindGroupMisses, 2);
    });
  });
}

final class _Token {
  const _Token(this.label);

  final String label;
}
