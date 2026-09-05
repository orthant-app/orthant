import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const docs = defineCollection({
  loader: glob({ pattern: '*.{md,mdx}', base: './src/content/docs' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    // Three groups, ordered by what a visitor is doing: getting it working,
    // using it, keeping it working. `order` sorts within a group.
    group: z.enum(['start', 'place', 'help']),
    order: z.number(),
  }),
});

const changelog = defineCollection({
  loader: glob({ pattern: '*.md', base: './src/content/changelog' }),
  schema: z.object({
    version: z.string().regex(/^\d+\.\d+\.\d+(-[a-z]+\.\d+)?$/),
    build: z.number().int().positive(),
    channel: z.enum(['stable', 'beta']),
    // False until the release is verified live. A version-bump commit builds
    // the site before the release is approved, so treating that build as
    // publication would advertise a version /download does not serve.
    published: z.boolean(),
    date: z.date(),
  }),
});

export const collections = { docs, changelog };
